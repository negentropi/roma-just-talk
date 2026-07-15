import Foundation
import AVFoundation
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
}
