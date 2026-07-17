import Foundation
import Testing
@testable import VoiceInk

@Suite(.serialized)
struct CoreAudioPreRollBufferTests {
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
}
