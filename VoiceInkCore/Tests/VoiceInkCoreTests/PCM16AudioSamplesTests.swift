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

    func testFloatSamplesRejectTooSmallWAVData() {
        let data = Data(repeating: 0, count: VoiceInkPCM16Audio.wavHeaderByteCount)

        XCTAssertNil(VoiceInkPCM16Audio.floatSamples(fromWAVData: data))
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

    private func pcm16Data(samples: [Int16]) -> Data {
        var data = Data()
        for sample in samples {
            let littleEndian = sample.littleEndian
            data.append(UInt8(truncatingIfNeeded: littleEndian))
            data.append(UInt8(truncatingIfNeeded: littleEndian >> 8))
        }
        return data
    }
}
