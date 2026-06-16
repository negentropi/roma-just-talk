import Foundation
import Testing
@testable import VoiceInk

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

        #expect(!gate.queueLiveChunkIfNeeded(first))

        gate.begin()
        #expect(gate.queueLiveChunkIfNeeded(first))
        #expect(gate.queueLiveChunkIfNeeded(second))
        #expect(gate.finish() == [first, second])
        #expect(!gate.queueLiveChunkIfNeeded(Data([3])))
    }

    @Test func streamingEmissionGateDropsQueuedChunksWhenCanceled() {
        var gate = PreRollStreamingEmissionGate()

        gate.begin()
        #expect(gate.queueLiveChunkIfNeeded(Data([1])))

        gate.cancel()

        #expect(gate.finish().isEmpty)
        #expect(!gate.queueLiveChunkIfNeeded(Data([2])))
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
