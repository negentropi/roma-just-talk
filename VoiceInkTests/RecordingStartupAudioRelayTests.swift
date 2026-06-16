import Foundation
import Testing
@testable import VoiceInk

private final class LockedRelayChunks: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [Data] = []

    func append(_ data: Data) {
        lock.lock()
        chunks.append(data)
        lock.unlock()
    }

    func snapshot() -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return chunks
    }
}

struct RecordingStartupAudioRelayTests {
    @Test func installSinkReplaysBufferedChunksAndForwardsLaterChunks() {
        let relay = RecordingStartupAudioRelay()
        let received = LockedRelayChunks()

        relay.handle(Data([1]))
        relay.handle(Data([2]))
        relay.installSink { received.append($0) }
        relay.handle(Data([3]))
        relay.clear()

        #expect(received.snapshot() == [Data([1]), Data([2]), Data([3])])
    }

    @Test func clearDropsBufferedChunksBeforeSinkInstall() {
        let relay = RecordingStartupAudioRelay()
        let received = LockedRelayChunks()

        relay.handle(Data([1]))
        relay.clear()
        relay.installSink { received.append($0) }
        relay.handle(Data([2]))
        relay.clear()

        #expect(received.snapshot() == [Data([2])])
    }
}
