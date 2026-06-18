import Foundation
@testable import VoiceInkCore

final class RollingAudioBufferTests: XCTestCase {
    func testAppendKeepsChunksWithinMaxBytes() {
        var buffer = VoiceInkRollingAudioBuffer(maxBytes: 6)

        buffer.append(Data([0, 1]))
        buffer.append(Data([2, 3]))
        buffer.append(Data([4, 5]))

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.bytes, 6)
        XCTAssertEqual(buffer.chunksSnapshot(), [
            Data([0, 1]),
            Data([2, 3]),
            Data([4, 5])
        ])
        XCTAssertEqual(buffer.dataSnapshot(), Data([0, 1, 2, 3, 4, 5]))
    }

    func testAppendDropsWholeOldestChunksWhenOverflowCoversChunk() {
        var buffer = VoiceInkRollingAudioBuffer(maxBytes: 4)

        buffer.append(Data([0, 1]))
        buffer.append(Data([2, 3]))
        buffer.append(Data([4, 5]))

        XCTAssertEqual(buffer.count, 2)
        XCTAssertEqual(buffer.bytes, 4)
        XCTAssertEqual(buffer.chunksSnapshot(), [
            Data([2, 3]),
            Data([4, 5])
        ])
    }

    func testAppendPartiallyTrimsOldestChunkWhenOverflowIsSmallerThanChunk() {
        var buffer = VoiceInkRollingAudioBuffer(maxBytes: 5)

        buffer.append(Data([0, 1, 2, 3]))
        buffer.append(Data([4, 5, 6]))

        XCTAssertEqual(buffer.count, 2)
        XCTAssertEqual(buffer.bytes, 5)
        XCTAssertEqual(buffer.chunksSnapshot(), [
            Data([2, 3]),
            Data([4, 5, 6])
        ])
        XCTAssertEqual(buffer.dataSnapshot(), Data([2, 3, 4, 5, 6]))
    }

    func testUpdateMaxBytesTrimsAndClampsNegativeCapacity() {
        var buffer = VoiceInkRollingAudioBuffer(maxBytes: 8)
        buffer.append(Data([0, 1, 2]))
        buffer.append(Data([3, 4, 5]))

        buffer.updateMaxBytes(4)

        XCTAssertEqual(buffer.count, 2)
        XCTAssertEqual(buffer.bytes, 4)
        XCTAssertEqual(buffer.dataSnapshot(), Data([2, 3, 4, 5]))

        buffer.updateMaxBytes(-1)

        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.bytes, 0)
        XCTAssertEqual(buffer.dataSnapshot(), Data())
    }

    func testAppendIgnoresEmptyChunksAndZeroCapacity() {
        var buffer = VoiceInkRollingAudioBuffer(maxBytes: 0)

        buffer.append(Data([0, 1]))
        buffer.updateMaxBytes(4)
        buffer.append(Data())

        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.bytes, 0)
        XCTAssertEqual(buffer.chunksSnapshot(), [])
    }

    func testRemoveAllClearsChunksAndBytes() {
        var buffer = VoiceInkRollingAudioBuffer(maxBytes: 8)
        buffer.append(Data([0, 1]))
        buffer.append(Data([2, 3]))

        buffer.removeAll()

        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.bytes, 0)
        XCTAssertEqual(buffer.chunksSnapshot(), [])
    }
}
