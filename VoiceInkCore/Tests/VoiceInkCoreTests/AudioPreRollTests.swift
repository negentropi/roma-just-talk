import Foundation
@testable import VoiceInkCore

final class AudioPreRollTests: XCTestCase {
    func testPreRollKeepsNewestSamplesInChronologicalOrder() {
        let buffer = VoiceInkPCM16PreRollBuffer(sampleRate: 2, durationSeconds: 2)

        append([1, 2, 3], to: buffer)
        append([4, 5, 6], to: buffer)

        XCTAssertEqual(samples(in: buffer.snapshotData()), [3, 4, 5, 6])
    }

    func testPreRollReplacesBufferWhenChunkExceedsCapacity() {
        let buffer = VoiceInkPCM16PreRollBuffer(sampleRate: 2, durationSeconds: 2)

        append([1, 2, 3, 4, 5, 6], to: buffer)

        XCTAssertEqual(samples(in: buffer.snapshotData()), [3, 4, 5, 6])
    }

    func testPreRollClearStartsFreshCaptureWindow() {
        let buffer = VoiceInkPCM16PreRollBuffer(sampleRate: 2, durationSeconds: 2)
        append([1, 2, 3], to: buffer)

        buffer.clear()
        append([9, 10], to: buffer)

        XCTAssertEqual(samples(in: buffer.snapshotData()), [9, 10])
    }

    func testPreRollResizeClearsExistingWindowAndUsesNewCapacity() {
        let buffer = VoiceInkPCM16PreRollBuffer(sampleRate: 2, durationSeconds: 2)
        append([1, 2, 3, 4], to: buffer)

        buffer.resize(sampleRate: 2, durationSeconds: 1)
        append([5, 6, 7], to: buffer)

        XCTAssertEqual(samples(in: buffer.snapshotData()), [6, 7])
    }

    private func append(_ samples: [Int16], to buffer: VoiceInkPCM16PreRollBuffer) {
        samples.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return }
            buffer.append(baseAddress, sampleCount: pointer.count)
        }
    }

    private func samples(in data: Data) -> [Int16] {
        data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Int16.self))
        }
    }
}
