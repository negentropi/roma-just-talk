import Foundation

public enum VoiceInkAudioPreRollPolicy {
    public static let durationSeconds: TimeInterval = 3
    public static let streamingChunkDurationSeconds: TimeInterval = 0.1
}

public final class VoiceInkPCM16PreRollBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: UnsafeMutablePointer<Int16>
    private var capacity: Int
    private var writeIndex = 0
    private var availableSamples = 0

    public init(
        sampleRate: Int = VoiceInkPCM16Audio.mono16kSampleRateHz,
        durationSeconds: TimeInterval = VoiceInkAudioPreRollPolicy.durationSeconds
    ) {
        capacity = max(Int((Double(sampleRate) * durationSeconds).rounded()), 1)
        samples = UnsafeMutablePointer<Int16>.allocate(capacity: capacity)
        samples.initialize(repeating: 0, count: capacity)
    }

    deinit {
        samples.deallocate()
    }

    public func append(_ input: UnsafePointer<Int16>, sampleCount: Int) {
        guard sampleCount > 0 else { return }

        lock.lock()
        defer { lock.unlock() }

        if sampleCount >= capacity {
            samples.update(from: input.advanced(by: sampleCount - capacity), count: capacity)
            writeIndex = 0
            availableSamples = capacity
            return
        }

        let firstCopyCount = min(sampleCount, capacity - writeIndex)
        samples.advanced(by: writeIndex).update(from: input, count: firstCopyCount)

        let remaining = sampleCount - firstCopyCount
        if remaining > 0 {
            samples.update(from: input.advanced(by: firstCopyCount), count: remaining)
        }

        writeIndex = (writeIndex + sampleCount) % capacity
        availableSamples = min(capacity, availableSamples + sampleCount)
    }

    public func snapshotData() -> Data {
        lock.lock()
        defer { lock.unlock() }

        guard availableSamples > 0 else { return Data() }

        let start = (writeIndex - availableSamples + capacity) % capacity
        let firstSampleCount = min(availableSamples, capacity - start)
        let secondSampleCount = availableSamples - firstSampleCount

        var data = Data(count: availableSamples * VoiceInkPCM16Audio.bytesPerSample)
        data.withUnsafeMutableBytes { rawBuffer in
            guard let destination = rawBuffer.baseAddress else { return }

            let firstByteCount = firstSampleCount * VoiceInkPCM16Audio.bytesPerSample
            destination.copyMemory(
                from: UnsafeRawPointer(samples.advanced(by: start)),
                byteCount: firstByteCount
            )

            if secondSampleCount > 0 {
                destination.advanced(by: firstByteCount).copyMemory(
                    from: UnsafeRawPointer(samples),
                    byteCount: secondSampleCount * VoiceInkPCM16Audio.bytesPerSample
                )
            }
        }
        return data
    }

    public func resize(sampleRate: Int, durationSeconds: TimeInterval) {
        let newCapacity = max(Int((Double(sampleRate) * durationSeconds).rounded()), 1)

        lock.lock()
        guard newCapacity != capacity else {
            lock.unlock()
            return
        }

        let oldSamples = samples
        samples = UnsafeMutablePointer<Int16>.allocate(capacity: newCapacity)
        samples.initialize(repeating: 0, count: newCapacity)
        oldSamples.deallocate()
        capacity = newCapacity
        writeIndex = 0
        availableSamples = 0
        lock.unlock()
    }

    public func clear() {
        lock.lock()
        writeIndex = 0
        availableSamples = 0
        lock.unlock()
    }
}
