import Foundation

public enum VoiceInkPCM16Audio {
    public static let mono16kSampleRateHz = 16_000
    public static let mono16kSampleRate = Double(mono16kSampleRateHz)
    public static let monoChannelCount = 1
    public static let bitsPerSample = 16
    public static let bytesPerSample = MemoryLayout<Int16>.size
    public static let wavHeaderByteCount = 44

    public static func floatSamples(fromLittleEndianData data: Data, startingAt startByteOffset: Int = 0) -> [Float] {
        guard startByteOffset >= 0 else { return [] }
        let readableByteCount = data.count - startByteOffset
        guard readableByteCount >= bytesPerSample else { return [] }

        return data.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return [] }

            let sampleCount = readableByteCount / bytesPerSample
            var samples: [Float] = []
            samples.reserveCapacity(sampleCount)

            for sampleIndex in 0..<sampleCount {
                let byteIndex = startByteOffset + sampleIndex * bytesPerSample
                let rawValue = UInt16(bytes[byteIndex]) | (UInt16(bytes[byteIndex + 1]) << 8)
                let sample = Int16(bitPattern: rawValue)
                samples.append(max(-1.0, min(Float(sample) / 32767.0, 1.0)))
            }

            return samples
        }
    }

    public static func floatSamples(fromWAVData data: Data) -> [Float]? {
        guard data.count > wavHeaderByteCount else { return nil }
        return floatSamples(fromLittleEndianData: data, startingAt: wavHeaderByteCount)
    }

    public static func sampleCount(inData data: Data) -> Int {
        data.count / bytesPerSample
    }

    public static func sampleCount(forMono16kDuration seconds: Double) -> Int {
        Int((seconds * Double(mono16kSampleRateHz)).rounded())
    }

    public static func byteCount(forMono16kDuration seconds: Double) -> Int {
        Int((seconds * Double(mono16kSampleRateHz) * Double(bytesPerSample)).rounded())
    }

    public static func duration(forMono16kData data: Data) -> TimeInterval {
        TimeInterval(sampleCount(inData: data)) / Double(mono16kSampleRateHz)
    }
}
