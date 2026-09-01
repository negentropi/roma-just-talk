function pcm16Wave(buffer) {
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
      if (chunkSize < 16) throw new Error("Invalid fmt chunk in the WAV fixture.");
      format = {
        audioFormat: buffer.readUInt16LE(chunkStart),
        channels: buffer.readUInt16LE(chunkStart + 2),
        sampleRate: buffer.readUInt32LE(chunkStart + 4),
        blockAlign: buffer.readUInt16LE(chunkStart + 12),
        bitsPerSample: buffer.readUInt16LE(chunkStart + 14),
      };
    } else if (chunkId === "data") {
      dataStart = chunkStart;
      dataSize = chunkSize;
    }
    offset = chunkEnd + (chunkSize % 2);
  }

  const expectedBlockAlign = (format?.channels || 0) * 2;
  if (
    format?.audioFormat !== 1
    || format.bitsPerSample !== 16
    || !format.sampleRate
    || format.blockAlign !== expectedBlockAlign
    || dataStart === undefined
    || !dataSize
    || dataSize % expectedBlockAlign !== 0
  ) {
    throw new Error("The real-audio fixture must contain complete 16-bit PCM frames.");
  }
  return { ...format, dataStart, dataSize };
}

export function pcm16WaveRmsDecibelsFullScale(buffer) {
  const wave = pcm16Wave(buffer);
  const sampleCount = wave.dataSize / 2;
  let squaredTotal = 0;
  for (let offset = wave.dataStart; offset < wave.dataStart + wave.dataSize; offset += 2) {
    const sample = buffer.readInt16LE(offset) / 32_768;
    squaredTotal += sample * sample;
  }
  const rms = Math.sqrt(squaredTotal / sampleCount);
  return rms > 0 ? 20 * Math.log10(rms) : Number.NEGATIVE_INFINITY;
}

export function pcm16WaveDurationSeconds(buffer) {
  const wave = pcm16Wave(buffer);
  return wave.dataSize / wave.blockAlign / wave.sampleRate;
}

export function pcm16WaveEnvelope(buffer, { seconds, windowMilliseconds }) {
  const wave = pcm16Wave(buffer);
  const totalFrames = Math.min(
    wave.dataSize / wave.blockAlign,
    Math.round(wave.sampleRate * seconds),
  );
  const framesPerWindow = Math.max(1, Math.round(wave.sampleRate * windowMilliseconds / 1_000));
  const envelope = [];
  for (let firstFrame = 0; firstFrame < totalFrames; firstFrame += framesPerWindow) {
    const lastFrame = Math.min(totalFrames, firstFrame + framesPerWindow);
    let squaredTotal = 0;
    let sampleCount = 0;
    for (let frame = firstFrame; frame < lastFrame; frame += 1) {
      for (let channel = 0; channel < wave.channels; channel += 1) {
        const offset = wave.dataStart + frame * wave.blockAlign + channel * 2;
        const sample = buffer.readInt16LE(offset) / 32_768;
        squaredTotal += sample * sample;
        sampleCount += 1;
      }
    }
    envelope.push(Math.sqrt(squaredTotal / sampleCount));
  }
  return envelope;
}

export function maximumEnvelopeCorrelation(expected, actual, minimumOverlapRatio = 0.8) {
  const minimumOverlap = Math.ceil(expected.length * minimumOverlapRatio);
  let maximum = Number.NEGATIVE_INFINITY;
  for (let lag = -expected.length + minimumOverlap; lag <= actual.length - minimumOverlap; lag += 1) {
    const expectedStart = Math.max(0, -lag);
    const expectedEnd = Math.min(expected.length, actual.length - lag);
    const count = expectedEnd - expectedStart;
    if (count < minimumOverlap) continue;

    let expectedTotal = 0;
    let actualTotal = 0;
    for (let index = expectedStart; index < expectedEnd; index += 1) {
      expectedTotal += expected[index];
      actualTotal += actual[index + lag];
    }
    const expectedMean = expectedTotal / count;
    const actualMean = actualTotal / count;
    let covariance = 0;
    let expectedVariance = 0;
    let actualVariance = 0;
    for (let index = expectedStart; index < expectedEnd; index += 1) {
      const expectedDelta = expected[index] - expectedMean;
      const actualDelta = actual[index + lag] - actualMean;
      covariance += expectedDelta * actualDelta;
      expectedVariance += expectedDelta * expectedDelta;
      actualVariance += actualDelta * actualDelta;
    }
    const denominator = Math.sqrt(expectedVariance * actualVariance);
    if (denominator > 0) maximum = Math.max(maximum, covariance / denominator);
  }
  return maximum;
}
