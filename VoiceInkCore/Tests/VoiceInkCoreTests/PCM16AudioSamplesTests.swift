import Foundation
@testable import VoiceInkCore

final class PCM16AudioSamplesTests: XCTestCase {
    func testFloatSamplesDecodeLittleEndianPCM16Data() {
        let data = pcm16Data(samples: [Int16.min, -16_384, 0, 16_384, Int16.max])

        let samples = VoiceInkPCM16Audio.floatSamples(fromLittleEndianData: data)

        XCTAssertEqual(samples.count, 5)
        XCTAssertEqual(samples[0], -1.0)
        XCTAssertEqual(samples[1], Float(-16_384) / 32_767.0, accuracy: 0.0001)
        XCTAssertEqual(samples[2], 0.0)
        XCTAssertEqual(samples[3], Float(16_384) / 32_767.0, accuracy: 0.0001)
        XCTAssertEqual(samples[4], 1.0)
    }

    func testFloatSamplesCanStartAfterWAVHeader() {
        var data = Data(repeating: 0, count: VoiceInkPCM16Audio.wavHeaderByteCount)
        data.append(pcm16Data(samples: [-1_000, 1_000]))

        let samples = VoiceInkPCM16Audio.floatSamples(fromWAVData: data)

        XCTAssertEqual(samples, [
            Float(-1_000) / 32_767.0,
            Float(1_000) / 32_767.0
        ])
    }

    func testFloatSamplesReadPCMDataChunkAfterExtraWAVChunk() {
        let data = wavDataWithExtraChunk(samples: [-2_000, 2_000])

        let samples = VoiceInkPCM16Audio.floatSamples(fromWAVData: data)

        XCTAssertEqual(samples, [
            Float(-2_000) / 32_767.0,
            Float(2_000) / 32_767.0
        ])
    }

    func testLittleEndianPCM16DataReadsPCMDataChunkAfterExtraWAVChunk() {
        let data = wavDataWithExtraChunk(samples: [-2_000, 2_000])

        XCTAssertEqual(
            VoiceInkPCM16Audio.littleEndianPCM16Data(fromWAVData: data),
            pcm16Data(samples: [-2_000, 2_000])
        )
    }

    func testWAVDataWritesCanonicalMono16kPCM16DataChunk() {
        let pcmData = pcm16Data(samples: [-2_000, 2_000])
        let wavData = VoiceInkPCM16Audio.wavData(fromLittleEndianPCM16Data: pcmData)

        XCTAssertEqual(VoiceInkPCM16Audio.littleEndianPCM16Data(fromWAVData: wavData), pcmData)
        XCTAssertEqual(VoiceInkPCM16Audio.floatSamples(fromWAVData: wavData), [
            Float(-2_000) / 32_767.0,
            Float(2_000) / 32_767.0
        ])
    }

    func testFloatSamplesRejectTooSmallWAVData() {
        let data = Data(repeating: 0, count: VoiceInkPCM16Audio.wavHeaderByteCount)

        XCTAssertNil(VoiceInkPCM16Audio.floatSamples(fromWAVData: data))
    }

    func testFloatSamplesCanReadWAVFileURL() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let fileURL = baseDirectory.appendingPathComponent("recording.wav")
        var data = Data(repeating: 0, count: VoiceInkPCM16Audio.wavHeaderByteCount)
        data.append(pcm16Data(samples: [-2_000, 2_000]))
        try data.write(to: fileURL)

        let samples = try VoiceInkPCM16Audio.floatSamples(fromWAVFileAt: fileURL)

        XCTAssertEqual(samples, [
            Float(-2_000) / 32_767.0,
            Float(2_000) / 32_767.0
        ])
    }

    func testFloatSamplesRejectTooSmallWAVFileURL() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let fileURL = baseDirectory.appendingPathComponent("empty.wav")
        try Data(repeating: 0, count: VoiceInkPCM16Audio.wavHeaderByteCount).write(to: fileURL)

        XCTAssertNil(try VoiceInkPCM16Audio.floatSamples(fromWAVFileAt: fileURL))
    }

    func testLeveledFloatSamplesFromWAVDataBoostsQuietSpeechTowardTargetPeak() {
        let samples = VoiceInkPCM16Audio.leveledFloatSamples(
            fromWAVData: wavData(samples: [-100, -50, 50, 100]),
            targetPeak: 1_000,
            noiseFloorPeak: 10,
            maxGain: 20
        )

        XCTAssertEqual(samples, [
            Float(-1_000) / 32_767.0,
            Float(-500) / 32_767.0,
            Float(500) / 32_767.0,
            Float(1_000) / 32_767.0
        ])
    }

    func testLeveledFloatSamplesFromWAVDataLeavesNoiseFloorUnchanged() {
        let samples = VoiceInkPCM16Audio.leveledFloatSamples(
            fromWAVData: wavData(samples: [-4, 0, 4]),
            targetPeak: 1_000,
            noiseFloorPeak: 10,
            maxGain: 20
        )

        XCTAssertEqual(samples, [
            Float(-4) / 32_767.0,
            0,
            Float(4) / 32_767.0
        ])
        XCTAssertNil(
            VoiceInkPCM16Audio.leveledFloatSamples(
                fromWAVData: Data(repeating: 0, count: VoiceInkPCM16Audio.wavHeaderByteCount),
                targetPeak: 1_000,
                noiseFloorPeak: 10,
                maxGain: 20
            )
        )
    }

    func testWhisperAudioSamplesUseSharedLevelingDefaultsForWAVData() {
        let samples = VoiceInkWhisperAudioSamples.floatSamples(
            fromWAVData: wavData(samples: [-1_000, 1_000])
        )

        XCTAssertEqual(samples, [
            Float(-12_000) / 32_767.0,
            Float(12_000) / 32_767.0
        ])
    }

    func testWhisperAudioSamplesCanReadWAVFileURL() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let fileURL = baseDirectory.appendingPathComponent("recording.wav")
        try wavData(samples: [-1_000, 1_000]).write(to: fileURL)

        let samples = try VoiceInkWhisperAudioSamples.floatSamples(fromWAVFileAt: fileURL)

        XCTAssertEqual(samples, [
            Float(-12_000) / 32_767.0,
            Float(12_000) / 32_767.0
        ])
    }

    func testNormalizedMonoFloatSamplesPreserveSingleChannelNormalization() {
        let input: [Float] = [-0.25, 0.5, 1.0]

        let samples = VoiceInkPCM16Audio.normalizedMonoFloatSamples(
            channelCount: 1,
            frameLength: input.count,
            sampleAt: { _, frame in input[frame] }
        )

        XCTAssertEqual(samples, [-0.25, 0.5, 1.0])
    }

    func testNormalizedMonoFloatSamplesAverageChannelsBeforeNormalizing() {
        let channels: [[Float]] = [
            [0.0, 0.5, 1.0],
            [0.0, 1.0, -1.0]
        ]

        let samples = VoiceInkPCM16Audio.normalizedMonoFloatSamples(
            channelCount: channels.count,
            frameLength: channels[0].count,
            sampleAt: { channel, frame in channels[channel][frame] }
        )

        XCTAssertEqual(samples, [0.0, 1.0, 0.0])
    }

    func testNormalizedMonoFloatSamplesKeepSilenceAtZero() {
        let samples = VoiceInkPCM16Audio.normalizedMonoFloatSamples(
            channelCount: 2,
            frameLength: 3,
            sampleAt: { _, _ in 0.0 }
        )

        XCTAssertEqual(samples, [0.0, 0.0, 0.0])
        XCTAssertEqual(
            VoiceInkPCM16Audio.normalizedMonoFloatSamples(
                channelCount: 0,
                frameLength: 3,
                sampleAt: { _, _ in 1.0 }
            ),
            []
        )
    }

    func testPCM16SamplesClampAndScaleFloatSamples() {
        let samples = VoiceInkPCM16Audio.pcm16Samples(
            fromFloatSamples: [-2.0, -1.0, -0.5, 0.0, 0.5, 1.0, 2.0]
        )

        XCTAssertEqual(samples, [
            Int16(-32_767),
            Int16(-32_767),
            Int16(-16_383),
            Int16(0),
            Int16(16_383),
            Int16(32_767),
            Int16(32_767)
        ])
    }

    func testPCM16SamplesReturnEmptyForEmptyInput() {
        XCTAssertEqual(VoiceInkPCM16Audio.pcm16Samples(fromFloatSamples: []), [])
    }

    func testLeveledLittleEndianDataBoostsQuietSpeechTowardTargetPeak() {
        let data = pcm16Data(samples: [-100, -50, 50, 100])

        let leveled = VoiceInkPCM16Audio.leveledLittleEndianData(
            data,
            targetPeak: 1_000,
            noiseFloorPeak: 10,
            maxGain: 20
        )

        XCTAssertEqual(pcm16Samples(from: leveled), [-1_000, -500, 500, 1_000])
    }

    func testLeveledLittleEndianDataLeavesSilenceAndNoiseFloorUnchanged() {
        let silence = pcm16Data(samples: [0, 0, 0])
        let noiseFloor = pcm16Data(samples: [-4, 0, 4])

        XCTAssertEqual(
            VoiceInkPCM16Audio.leveledLittleEndianData(
                silence,
                targetPeak: 1_000,
                noiseFloorPeak: 10,
                maxGain: 20
            ),
            silence
        )
        XCTAssertEqual(
            VoiceInkPCM16Audio.leveledLittleEndianData(
                noiseFloor,
                targetPeak: 1_000,
                noiseFloorPeak: 10,
                maxGain: 20
            ),
            noiseFloor
        )
    }

    func testConvertedMonoPCM16SampleCountUsesExistingTruncatedResamplePolicy() {
        XCTAssertEqual(
            VoiceInkPCM16Audio.convertedMonoPCM16SampleCount(
                frameCount: 3,
                inputSampleRate: 48_000,
                outputSampleRate: 16_000
            ),
            1
        )
        XCTAssertEqual(
            VoiceInkPCM16Audio.convertedMonoPCM16SampleCount(
                frameCount: 3,
                inputSampleRate: 16_000,
                outputSampleRate: 16_000
            ),
            3
        )
        XCTAssertEqual(
            VoiceInkPCM16Audio.convertedMonoPCM16SampleCount(
                frameCount: 3,
                inputSampleRate: 0,
                outputSampleRate: 16_000
            ),
            0
        )
    }

    func testWriteMonoPCM16SamplesAveragesInterleavedChannelsWithoutResampling() {
        let result = writeMonoPCM16Samples(
            input: [
                0.5, -0.5,
                1.0, 1.0,
                -2.0, -2.0
            ],
            frameCount: 3,
            channelCount: 2,
            inputSampleRate: 16_000,
            outputSampleRate: 16_000,
            outputCapacity: 3
        )

        XCTAssertEqual(result.written, 3)
        XCTAssertEqual(result.output, [0, 32_767, -32_768])
    }

    func testWriteMonoPCM16SamplesLinearlyResamplesInterleavedChannels() {
        let result = writeMonoPCM16Samples(
            input: [0.0, 1.0, 0.0],
            frameCount: 3,
            channelCount: 1,
            inputSampleRate: 2,
            outputSampleRate: 4,
            outputCapacity: 6
        )

        XCTAssertEqual(result.written, 6)
        XCTAssertEqual(result.output, [0, 16_383, 32_767, 16_383, 0, 0])
    }

    func testWriteMonoPCM16SamplesRejectsInsufficientCapacityAndInvalidInput() {
        let result = writeMonoPCM16Samples(
            input: [0.0, 1.0, 0.0],
            frameCount: 3,
            channelCount: 1,
            inputSampleRate: 2,
            outputSampleRate: 4,
            outputCapacity: 2,
            fillValue: 123
        )

        XCTAssertEqual(result.written, 0)
        XCTAssertEqual(result.output, [123, 123])
    }

    func testDurationAndByteCountUseMono16kPCM16Format() {
        XCTAssertEqual(VoiceInkPCM16Audio.mono16kSampleRateHz, 16_000)
        XCTAssertEqual(VoiceInkPCM16Audio.mono16kSampleRate, 16_000.0)
        XCTAssertEqual(VoiceInkPCM16Audio.monoChannelCount, 1)
        XCTAssertEqual(VoiceInkPCM16Audio.bitsPerSample, 16)
        XCTAssertEqual(VoiceInkPCM16Audio.bytesPerSample, 2)
        XCTAssertFalse(VoiceInkPCM16Audio.isBigEndian)
        XCTAssertFalse(VoiceInkPCM16Audio.isFloatingPoint)
        XCTAssertEqual(VoiceInkPCM16Audio.byteCount(forMono16kDuration: 0.1), 3_200)
        XCTAssertEqual(VoiceInkPCM16Audio.sampleCount(forMono16kDuration: 0.1), 1_600)

        let oneSecond = Data(repeating: 0, count: VoiceInkPCM16Audio.byteCount(forMono16kDuration: 1))
        XCTAssertEqual(VoiceInkPCM16Audio.duration(forMono16kData: oneSecond), 1)
    }

    func testMonoPCM16ChunksSplitDataOnSampleAlignedByteCounts() {
        let data = Data([0, 1, 2, 3, 4, 5, 6, 7])

        let chunks = VoiceInkPCM16Audio.monoPCM16Chunks(from: data, maxByteCount: 4)

        XCTAssertEqual(chunks, [
            Data([0, 1, 2, 3]),
            Data([4, 5, 6, 7])
        ])
    }

    func testMonoPCM16ChunksDropTrailingPartialSample() {
        let data = Data([0, 1, 2, 3, 4])

        let chunks = VoiceInkPCM16Audio.monoPCM16Chunks(from: data, maxByteCount: 4)

        XCTAssertEqual(chunks, [Data([0, 1, 2, 3])])
    }

    func testMonoPCM16ChunksAlignOddChunkSizeToSampleBoundary() {
        let data = Data([0, 1, 2, 3, 4, 5])

        let chunks = VoiceInkPCM16Audio.monoPCM16Chunks(from: data, maxByteCount: 3)

        XCTAssertEqual(chunks, [
            Data([0, 1]),
            Data([2, 3]),
            Data([4, 5])
        ])
    }

    func testMonoPCM16ChunksRejectEmptyDataAndTooSmallChunkSize() {
        XCTAssertEqual(VoiceInkPCM16Audio.monoPCM16Chunks(from: Data(), maxByteCount: 4), [])
        XCTAssertEqual(
            VoiceInkPCM16Audio.monoPCM16Chunks(from: Data([0, 1, 2, 3]), maxByteCount: 1),
            []
        )
    }

    private func pcm16Data(samples: [Int16]) -> Data {
        var data = Data()
        for sample in samples {
            let littleEndian = sample.littleEndian
            data.append(UInt8(truncatingIfNeeded: littleEndian))
            data.append(UInt8(truncatingIfNeeded: littleEndian >> 8))
        }
        return data
    }

    private func pcm16Samples(from data: Data) -> [Int16] {
        var samples: [Int16] = []
        samples.reserveCapacity(data.count / VoiceInkPCM16Audio.bytesPerSample)

        data.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for byteIndex in stride(from: 0, to: data.count - 1, by: VoiceInkPCM16Audio.bytesPerSample) {
                let rawValue = UInt16(bytes[byteIndex]) | (UInt16(bytes[byteIndex + 1]) << 8)
                samples.append(Int16(bitPattern: rawValue))
            }
        }

        return samples
    }

    private func wavData(samples: [Int16]) -> Data {
        var data = Data(repeating: 0, count: VoiceInkPCM16Audio.wavHeaderByteCount)
        data.append(pcm16Data(samples: samples))
        return data
    }

    private func wavDataWithExtraChunk(samples: [Int16]) -> Data {
        let pcmData = pcm16Data(samples: samples)
        var data = Data()
        appendASCII("RIFF", to: &data)
        appendUInt32LE(UInt32(4 + 24 + 10 + 8 + pcmData.count), to: &data)
        appendASCII("WAVE", to: &data)

        appendASCII("fmt ", to: &data)
        appendUInt32LE(16, to: &data)
        appendUInt16LE(1, to: &data)
        appendUInt16LE(UInt16(VoiceInkPCM16Audio.monoChannelCount), to: &data)
        appendUInt32LE(UInt32(VoiceInkPCM16Audio.mono16kSampleRateHz), to: &data)
        appendUInt32LE(UInt32(VoiceInkPCM16Audio.mono16kSampleRateHz * VoiceInkPCM16Audio.bytesPerSample), to: &data)
        appendUInt16LE(UInt16(VoiceInkPCM16Audio.bytesPerSample), to: &data)
        appendUInt16LE(UInt16(VoiceInkPCM16Audio.bitsPerSample), to: &data)

        appendASCII("JUNK", to: &data)
        appendUInt32LE(2, to: &data)
        data.append(contentsOf: [0x12, 0x34])

        appendASCII("data", to: &data)
        appendUInt32LE(UInt32(pcmData.count), to: &data)
        data.append(pcmData)
        return data
    }

    private func appendASCII(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
    }

    private func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        let littleEndian = value.littleEndian
        data.append(UInt8(truncatingIfNeeded: littleEndian))
        data.append(UInt8(truncatingIfNeeded: littleEndian >> 8))
    }

    private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        let littleEndian = value.littleEndian
        data.append(UInt8(truncatingIfNeeded: littleEndian))
        data.append(UInt8(truncatingIfNeeded: littleEndian >> 8))
        data.append(UInt8(truncatingIfNeeded: littleEndian >> 16))
        data.append(UInt8(truncatingIfNeeded: littleEndian >> 24))
    }

    private func writeMonoPCM16Samples(
        input: [Float32],
        frameCount: Int,
        channelCount: Int,
        inputSampleRate: Double,
        outputSampleRate: Double,
        outputCapacity: Int,
        fillValue: Int16 = 0
    ) -> (written: Int, output: [Int16]) {
        var output = Array(repeating: fillValue, count: outputCapacity)
        let written = input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                VoiceInkPCM16Audio.writeMonoPCM16Samples(
                    fromInterleavedFloat32Samples: inputBuffer.baseAddress!,
                    frameCount: frameCount,
                    channelCount: channelCount,
                    inputSampleRate: inputSampleRate,
                    outputSampleRate: outputSampleRate,
                    to: outputBuffer.baseAddress!,
                    outputCapacity: outputBuffer.count
                )
            }
        }
        return (written, output)
    }
}
