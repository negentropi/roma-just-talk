import Foundation
import AVFoundation
import Testing
@testable import VoiceInk

@Suite(.serialized)
struct CoreAudioPreRollBufferTests {
    @Test func snapshotKeepsChronologicalOrderAfterWrap() {
        let buffer = PCMPreRollBuffer(sampleRate: 4, seconds: 1.0)

        append([1, 2], to: buffer)
        append([3, 4, 5], to: buffer)

        #expect(samples(in: buffer.snapshotData()) == [2, 3, 4, 5])
    }

    @Test func snapshotKeepsLatestSamplesWhenAppendExceedsCapacity() {
        let buffer = PCMPreRollBuffer(sampleRate: 4, seconds: 1.0)

        append([10, 11, 12, 13, 14, 15], to: buffer)

        #expect(samples(in: buffer.snapshotData()) == [12, 13, 14, 15])
    }

    @Test func resizeClearsOldPreRollAudio() {
        let buffer = PCMPreRollBuffer(sampleRate: 4, seconds: 1.0)

        append([1, 2, 3], to: buffer)
        buffer.resize(sampleRate: 4, seconds: 2.0)

        #expect(samples(in: buffer.snapshotData()).isEmpty)
    }

    @Test func streamingEmissionGateQueuesLiveChunksUntilPreRollFinishes() {
        var gate = PreRollStreamingEmissionGate()
        let first = Data([1])
        let second = Data([2])

        let queuedBeforeBegin = gate.queueLiveChunkIfNeeded(first)
        #expect(!queuedBeforeBegin)

        gate.begin()
        let queuedFirst = gate.queueLiveChunkIfNeeded(first)
        let queuedSecond = gate.queueLiveChunkIfNeeded(second)
        let flushedChunks = gate.finish()
        let queuedAfterFinish = gate.queueLiveChunkIfNeeded(Data([3]))

        #expect(queuedFirst)
        #expect(queuedSecond)
        #expect(flushedChunks == [first, second])
        #expect(!queuedAfterFinish)
    }

    @Test func streamingEmissionGateDropsQueuedChunksWhenCanceled() {
        var gate = PreRollStreamingEmissionGate()

        gate.begin()
        let queuedBeforeCancel = gate.queueLiveChunkIfNeeded(Data([1]))
        #expect(queuedBeforeCancel)

        gate.cancel()
        let flushedChunks = gate.finish()
        let queuedAfterCancel = gate.queueLiveChunkIfNeeded(Data([2]))

        #expect(flushedChunks.isEmpty)
        #expect(!queuedAfterCancel)
    }

    @Test func pcmWriterCreatesReadableWAVFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceink-pcm-writer-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let values: [Int16] = [0, 1_000, -1_000, 0]
        let data = values.withUnsafeBytes { rawBuffer in
            Data(bytes: rawBuffer.baseAddress!, count: rawBuffer.count)
        }

        try PCM16WAVFileWriter.writeMono16k(data, to: url)

        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.sampleRate == 16_000)
        #expect(file.fileFormat.channelCount == 1)
        #expect(file.length == AVAudioFramePosition(values.count))
    }

    private func append(_ values: [Int16], to buffer: PCMPreRollBuffer) {
        values.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return }
            buffer.append(baseAddress, sampleCount: values.count)
        }
    }

    private func samples(in data: Data) -> [Int16] {
        data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Int16.self))
        }
    }
}
