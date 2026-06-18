import Foundation

public struct VoiceInkRollingAudioBuffer: Sendable {
    private var chunks: [Data] = []
    private var byteCount = 0
    private var maxBytes: Int

    public init(maxBytes: Int) {
        self.maxBytes = max(0, maxBytes)
    }

    public mutating func updateMaxBytes(_ newMaxBytes: Int) {
        maxBytes = max(0, newMaxBytes)
        trimIfNeeded()
    }

    public mutating func append(_ chunk: Data) {
        guard !chunk.isEmpty, maxBytes > 0 else { return }
        chunks.append(chunk)
        byteCount += chunk.count
        trimIfNeeded()
    }

    public mutating func removeAll(keepingCapacity: Bool = true) {
        chunks.removeAll(keepingCapacity: keepingCapacity)
        byteCount = 0
    }

    public func chunksSnapshot() -> [Data] {
        chunks
    }

    public func dataSnapshot() -> Data {
        chunks.reduce(into: Data()) { result, chunk in
            result.append(chunk)
        }
    }

    public var count: Int {
        chunks.count
    }

    public var bytes: Int {
        byteCount
    }

    private mutating func trimIfNeeded() {
        while byteCount > maxBytes, !chunks.isEmpty {
            let overflow = byteCount - maxBytes
            if overflow >= chunks[0].count {
                byteCount -= chunks.removeFirst().count
            } else {
                chunks[0].removeFirst(overflow)
                byteCount -= overflow
            }
        }
    }
}
